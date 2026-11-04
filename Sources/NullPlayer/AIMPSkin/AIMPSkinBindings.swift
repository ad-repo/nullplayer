/// One `Bindings/link`: the pin `target` of a control, item or provider reads `source`'s `pin`,
/// shaped by the link's `Expression` (`reference/layout.md` § *Visibility*). Read once as the skin
/// loads: what it reads resolved (`read`), the expression compiled.
struct AIMPSkinLink: Sendable {
    let source: String?
    let pin: String?
    let target: String?
    /// `source`'s `pin`, resolved against the skin's names.
    let read: AIMPSkinSource
    /// The `Expression` as written, and compiled; nil when the link has none or it does not parse,
    /// and the link passes its source's value on as it is.
    let expression: String?
    let shape: AIMPSkinExpression?
    /// What a `FileInfo` link shows of the track (`%Title`), or a hint's label.
    let textFormat: String?

    init(_ node: AIMPNode, names: AIMPSkinIndex.Names) {
        source = node["Source"]
        pin = node["SourcePin"]
        target = node["TargetPin"]
        read = AIMPSkinSource(source ?? "", pin ?? "", names: names)
        expression = node["Expression"]
        shape = expression.flatMap { names.expressions[$0] ?? AIMPSkinExpression($0) }
        textFormat = node["TextFormat"]
    }

    /// `value` as the link's `Expression` shapes it.
    func shaped(_ value: Double) -> Double { shape?.evaluate(value: value) ?? value }
}

/// A node's `Bindings`: its links in document order, and by the pin they feed.
struct AIMPSkinBindings: Sendable {
    /// Whether the node has a `Bindings` property at all, even an empty one (a label with none is
    /// as wide as its text: `AIMPSkinLayout.autoSized`).
    let declared: Bool
    let links: [AIMPSkinLink]
    private let byTarget: [String: [AIMPSkinLink]]

    init(_ node: AIMPNode, names: AIMPSkinIndex.Names) {
        let property = node.properties["Bindings"]
        declared = property != nil
        links = (property?.children("link") ?? []).map { AIMPSkinLink($0, names: names) }
        byTarget = Dictionary(grouping: links.filter { $0.target != nil }, by: { $0.target! })
    }

    /// The first link to `target`.
    subscript(target: String) -> AIMPSkinLink? { byTarget[target]?.first }

    /// Every link to `target`, in document order.
    func all(_ target: String) -> [AIMPSkinLink] { byTarget[target] ?? [] }
}
