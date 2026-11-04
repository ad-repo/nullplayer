import Foundation

/// AIMP's text templates, as `TextDisplay` `Template` and binding `TextFormat` write them:
/// `%IF(%R,%R - ,)%T`, `%Up(%R)`, `%Replace(%T,;, / )`, `%Char(44)`. Fields are `%T`/`%Title`,
/// `%R`/`%Artist`, `%A`/`%Album`; a function's arguments split on top-level commas. Unknown functions and
/// fields read empty.
enum AIMPSkinTemplate {
    /// `variables` are a text provider's inputs (`%Value1`, `%TextValue1`); `value` is the number a
    /// display is bound to, for `%time(MS;:;)`.
    static func format(_ template: String, host: AIMPSkinHostState, variables: [String: String] = [:], value: Double? = nil) -> String {
        var parser = Parser(chars: Array(template), host: host,
                            variables: Dictionary(variables.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { a, _ in a }),
                            value: value)
        return parser.text(until: [])
    }

    private struct Parser {
        let chars: [Character]
        let host: AIMPSkinHostState
        let variables: [String: String]
        let value: Double?
        var at = 0

        /// Text up to (not past) one of `stops` at this nesting level, or the end.
        mutating func text(until stops: Set<Character>) -> String {
            var out = ""
            while at < chars.count, !stops.contains(chars[at]) {
                if chars[at] == "%" { out += field() } else { out.append(chars[at]); at += 1 }
            }
            return out
        }

        mutating func field() -> String {
            at += 1  // %
            var name = ""
            while at < chars.count, chars[at].isLetter || chars[at].isNumber { name.append(chars[at]); at += 1 }
            guard at < chars.count, chars[at] == "(" else { return value(of: name) }
            at += 1
            var args: [String] = []
            while true {
                args.append(text(until: [",", ")"]))
                guard at < chars.count else { break }
                let c = chars[at]
                at += 1
                if c == ")" { break }
            }
            return call(name.lowercased(), args)
        }

        /// Short fields (`%T`) and long ones (`%Title`) both occur.
        func value(of field: String) -> String {
            if let variable = variables[field.lowercased()] { return variable }
            switch field {
            case "IN": return host.player.playlistIndex >= 0 ? String(host.player.playlistIndex + 1) : ""
            case "E", "FileExt": return host.player.fileType
            case "T", "Title", "FileName": return host.player.title
            case "R", "a", "Artist", "AlbumArtist": return host.player.artist
            case "A", "Album": return host.player.album
            case "Y", "Year": return host.player.year > 0 ? String(host.player.year) : ""
            case "G", "Genre": return host.player.genre
            case "B", "BitRate": return host.player.bitrate > 0 ? "\(host.player.bitrate) kbps" : ""
            case "H", "SampleRate": return host.player.sampleRate > 0 ? "\(host.player.sampleRate) Hz" : ""
            case "C", "Channels": return host.player.channels == 1 ? "Mono" : host.player.channels == 2 ? "Stereo" : host.player.channels > 2 ? "\(host.player.channels)" : ""
            case "L", "Duration":
                return host.player.durationSeconds > 0 ? String(format: "%d:%02d", host.player.durationSeconds / 60, host.player.durationSeconds % 60) : ""
            // The templates AIMP's user sets in its options: NullPlayer has none, so AIMP's own
            // title line, the artist then the title.
            case let user where user.hasPrefix("UserTemplate"):
                return host.player.artist.isEmpty ? host.player.title : host.player.artist + " - " + host.player.title
            case "S", "FileSize":
                return host.player.fileSize > 0 ? String(format: "%.2f MB", Double(host.player.fileSize) / 1_048_576) : ""
            default: return ""
            }
        }

        func call(_ name: String, _ args: [String]) -> String {
            switch name {
            case "if": return args.count >= 2 ? (!args[0].isEmpty ? args[1] : (args.count > 2 ? args[2] : "")) : ""
            case "up": return (args.first ?? "").uppercased()
            case "low": return (args.first ?? "").lowercased()
            case "replace":
                guard args.count >= 3, !args[1].isEmpty else { return args.first ?? "" }
                return args[0].replacingOccurrences(of: args[1], with: args[2])
            case "char": return (args.first.flatMap { Int($0) }.flatMap { UnicodeScalar($0) }).map { String(Character($0)) } ?? ""
            // `%IFEqual(a,b,then,else)` and kin compare numbers when both are, else text.
            case "ifequal", "ifgreater", "ifgreaterorequal", "ifless", "iflessorequal":
                guard args.count >= 3 else { return "" }
                let order: ComparisonResult
                if let a = Double(args[0].trimmingCharacters(in: .whitespaces)), let b = Double(args[1].trimmingCharacters(in: .whitespaces)) {
                    order = a < b ? .orderedAscending : a > b ? .orderedDescending : .orderedSame
                } else {
                    order = args[0].compare(args[1])
                }
                let holds = switch name {
                case "ifequal": order == .orderedSame
                case "ifgreater": order == .orderedDescending
                case "ifgreaterorequal": order != .orderedAscending
                case "ifless": order == .orderedAscending
                default: order != .orderedDescending
                }
                return holds ? args[2] : (args.count > 3 ? args[3] : "")
            // `%time(HMS;:;)`: the bound number of seconds as h:mm:ss (or m:ss for `MS`).
            case "time":
                let seconds = Int(value ?? 0)
                let spec = (args.first ?? "").split(separator: ";", omittingEmptySubsequences: false).map(String.init)
                let separator = spec.count > 1 && !spec[1].isEmpty ? spec[1] : ":"
                // The separator is the skin's text: joined, never a format string.
                let fields = (spec.first ?? "MS").uppercased().hasPrefix("H")
                    ? [String(seconds / 3_600), String(format: "%02d", seconds / 60 % 60), String(format: "%02d", seconds % 60)]
                    : [String(seconds / 60), String(format: "%02d", seconds % 60)]
                return fields.joined(separator: separator)
            default: return args.first ?? ""
            }
        }
    }
}
