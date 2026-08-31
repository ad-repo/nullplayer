import Foundation

struct WMPColor: Hashable, Codable, CustomStringConvertible {
    let red: UInt8
    let green: UInt8
    let blue: UInt8

    var description: String { String(format: "#%02X%02X%02X", red, green, blue) }
}

enum WMPBindingKind: String, Hashable, Codable {
    case property
    case enabled
}

enum WMPAttributeValue: Hashable {
    case literal(String)
    case jScript(String)
    case binding(kind: WMPBindingKind, path: String)
    case handler(event: String, source: String)
    case color(WMPColor)
    case resource(String)
    case unsupported(String)
}

struct WMPAttribute: Hashable {
    let name: String
    let rawValue: String
    let value: WMPAttributeValue
}

enum WMPAttributeParser {
    private static let resourceNames: Set<String> = [
        "image", "hoverimage", "downimage", "disabledimage", "mappingimage",
        "background", "backgroundimage", "foregroundimage", "cursor", "thumbnail"
    ]
    private static let colorNames: Set<String> = [
        "mappingcolor", "transparencycolor", "backgroundcolor", "foregroundcolor",
        "color", "bordercolor"
    ]
    private static let handlerNames: Set<String> = [
        "onclick", "onchange", "onload", "onclose", "ontimer",
        "onmouseover", "onmouseout", "onmousedown", "onmouseup",
        "openstatechange", "playstatechange", "status_onchange", "modechange",
        "buffering_onchange", "reception_onchange"
    ]

    static func parse(name: String, value raw: String) -> WMPAttributeValue {
        let lowerName = name.lowercased()
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if handlerNames.contains(lowerName) {
            return .handler(event: name, source: stripPrefix("jscript:", from: trimmed) ?? trimmed)
        }
        if let payload = stripPrefix("jscript:", from: trimmed) { return .jScript(payload) }
        if let payload = stripPrefix("wmpprop:", from: trimmed) {
            return .binding(kind: .property, path: payload.trimmingCharacters(in: .whitespaces))
        }
        if let payload = stripPrefix("wmpenabled:", from: trimmed) {
            return .binding(kind: .enabled, path: payload.trimmingCharacters(in: .whitespaces))
        }
        if colorNames.contains(lowerName), let color = color(from: trimmed) { return .color(color) }
        if resourceNames.contains(lowerName) {
            return isUnsupportedResource(trimmed) ? .unsupported(trimmed) : .resource(trimmed)
        }
        if isUnsupportedResource(trimmed) { return .unsupported(trimmed) }
        return .literal(raw)
    }

    static func isResourceAttribute(_ name: String) -> Bool {
        resourceNames.contains(name.lowercased())
    }

    private static func stripPrefix(_ prefix: String, from value: String) -> String? {
        guard value.lowercased().hasPrefix(prefix) else { return nil }
        return String(value.dropFirst(prefix.count))
    }

    private static func isUnsupportedResource(_ value: String) -> Bool {
        let lower = value.lowercased()
        return lower.hasPrefix("res://") || lower.hasPrefix("file:")
            || lower.hasPrefix("http:") || lower.hasPrefix("https:")
            || lower.hasPrefix("activex:")
    }

    private static func color(from value: String) -> WMPColor? {
        guard value.count == 7, value.first == "#",
              let number = UInt32(value.dropFirst(), radix: 16) else { return nil }
        return WMPColor(red: UInt8((number >> 16) & 0xFF),
                        green: UInt8((number >> 8) & 0xFF),
                        blue: UInt8(number & 0xFF))
    }
}
