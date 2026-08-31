import Foundation

struct WMPInventoryItem: Hashable, Codable {
    let name: String
    let count: Int
}

struct WMPCompatibilityReport: Equatable, Codable {
    let tags: [WMPInventoryItem]
    let attributes: [WMPInventoryItem]
    let resources: [WMPResourceRegistration]
    let scripts: [WMPScriptRegistration]
    let members: [WMPInventoryItem]
    let events: [WMPInventoryItem]
    let diagnostics: [WMPDiagnostic]

    init(graph: WMPObjectGraph, resources: [WMPResourceRegistration],
         scripts: [WMPScriptRegistration], diagnostics: [WMPDiagnostic],
         scriptSources: [String: String]) {
        var tagCounts: [String: Int] = [:]
        var attributeCounts: [String: Int] = [:]
        var memberCounts: [String: Int] = [:]
        var eventCounts: [String: Int] = [:]

        for node in graph.allNodes {
            tagCounts[node.authoredTagName.lowercased(), default: 0] += 1
            for attribute in node.attributes {
                let name = attribute.name.lowercased()
                attributeCounts[name, default: 0] += 1
                if name.hasPrefix("on") { eventCounts[name, default: 0] += 1 }
                switch attribute.value {
                case let .jScript(source), let .handler(_, source):
                    Self.collectMembers(in: source, into: &memberCounts)
                case let .binding(_, path):
                    memberCounts[path.lowercased(), default: 0] += 1
                default:
                    break
                }
            }
        }
        for source in scriptSources.keys.sorted(by: WMPPath.less).compactMap({ scriptSources[$0] }) {
            Self.collectMembers(in: source, into: &memberCounts)
            Self.collectEvents(in: source, into: &eventCounts)
        }
        tags = Self.inventory(tagCounts)
        attributes = Self.inventory(attributeCounts)
        self.resources = resources
        self.scripts = scripts
        members = Self.inventory(memberCounts)
        events = Self.inventory(eventCounts)
        self.diagnostics = diagnostics
    }

    private static func inventory(_ counts: [String: Int]) -> [WMPInventoryItem] {
        counts.keys.sorted(by: WMPPath.less).map { WMPInventoryItem(name: $0, count: counts[$0]!) }
    }

    private static func collectMembers(in source: String, into counts: inout [String: Int]) {
        let pattern = #"\b(?:player|theme|view|eq|vis|ipl|ddpl|metadata)(?:\.[A-Za-z_$][A-Za-z0-9_$]*)+"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return }
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        for match in regex.matches(in: source, range: range) {
            guard let swiftRange = Range(match.range, in: source) else { continue }
            counts[String(source[swiftRange]).lowercased(), default: 0] += 1
        }
    }

    private static func collectEvents(in source: String, into counts: inout [String: Int]) {
        let pattern = #"\b(?:on[A-Za-z][A-Za-z0-9_]*|[A-Za-z][A-Za-z0-9_]*_onchange)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return }
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        for match in regex.matches(in: source, range: range) {
            guard let swiftRange = Range(match.range, in: source) else { continue }
            counts[String(source[swiftRange]).lowercased(), default: 0] += 1
        }
    }
}
