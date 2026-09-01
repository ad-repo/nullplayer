import Foundation

struct WMPHitTarget: Hashable, Codable {
    let stableID: Int
    let nodeID: String?
    let kind: String
    let frame: WMPRect
    let action: WMPTransportAction?
    let sticky: Bool
    let enabled: Bool
}

struct WMPHitTester {
    let hits: [WMPHitMetadata]

    func hitTest(_ point: WMPPoint) -> WMPHitTarget? {
        for hit in hits.sorted(by: Self.frontToBack) {
            guard hit.enabled, hit.frame.contains(point),
                  hit.clipRect.map({ $0.contains(point) }) ?? true else { continue }
            if let mapping = hit.mappingImage {
                guard let stableID = mapping.node(at: point, in: hit.frame),
                      let target = hit.mappingTargets.first(where: { $0.stableID == stableID }),
                      target.enabled else { continue }
                return target
            }
            return WMPHitTarget(stableID: hit.stableID, nodeID: hit.nodeID, kind: hit.kind,
                                frame: hit.frame, action: hit.action, sticky: hit.sticky,
                                enabled: hit.enabled)
        }
        return nil
    }

    private static func frontToBack(_ lhs: WMPHitMetadata, _ rhs: WMPHitMetadata) -> Bool {
        lhs.zIndex == rhs.zIndex ? lhs.documentOrder > rhs.documentOrder : lhs.zIndex > rhs.zIndex
    }
}
